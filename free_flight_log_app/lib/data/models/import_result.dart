import '../../../utils/import_error_helper.dart';

/// Enum representing the result of importing an IGC file
enum ImportResultType {
  imported,  // Successfully imported as new flight
  replaced,  // Replaced existing flight
  skipped,   // Skipped due to user choice
  failed,    // Failed to import due to error
}

/// Model for tracking the result of importing a single IGC file
class ImportResult {
  final String fileName;
  final ImportResultType type;
  final String? errorMessage;
  final ImportErrorCategory? errorCategory;
  final int? flightId;
  final DateTime? flightDate;
  final String? flightTime;
  final int? duration;

  ImportResult({
    required this.fileName,
    required this.type,
    this.errorMessage,
    this.errorCategory,
    this.flightId,
    this.flightDate,
    this.flightTime,
    this.duration,
  });

  /// Create a successful import result
  ImportResult.imported({
    required this.fileName,
    required this.flightId,
    required this.flightDate,
    required this.flightTime,
    required this.duration,
  }) : type = ImportResultType.imported,
       errorMessage = null,
       errorCategory = null;

  /// Create a replaced flight result
  ImportResult.replaced({
    required this.fileName,
    required this.flightId,
    required this.flightDate,
    required this.flightTime,
    required this.duration,
  }) : type = ImportResultType.replaced,
       errorMessage = null,
       errorCategory = null;

  /// Create a skipped result
  ImportResult.skipped({
    required this.fileName,
    required this.flightDate,
    required this.flightTime,
    required this.duration,
  }) : type = ImportResultType.skipped,
       errorMessage = null,
       errorCategory = null,
       flightId = null;

  /// Create a failed import result
  ImportResult.failed({
    required this.fileName,
    required String rawErrorMessage,
  }) : type = ImportResultType.failed,
       flightId = null,
       flightDate = null,
       flightTime = null,
       duration = null,
       errorCategory = ImportErrorHelper.categorizeError(rawErrorMessage),
       errorMessage = ImportErrorHelper.getUserFriendlyMessage(rawErrorMessage, ImportErrorHelper.categorizeError(rawErrorMessage));
       
  /// Create a failed import result with explicit category and message
  ImportResult.failedWithCategory({
    required this.fileName,
    required this.errorMessage,
    required this.errorCategory,
  }) : type = ImportResultType.failed,
       flightId = null,
       flightDate = null,
       flightTime = null,
       duration = null;

  /// Get a human-readable description of the result
  String get description {
    switch (type) {
      case ImportResultType.imported:
        return 'Successfully imported';
      case ImportResultType.replaced:
        return 'Replaced existing flight';
      case ImportResultType.skipped:
        return 'Skipped (already exists)';
      case ImportResultType.failed:
        return errorMessage ?? 'Unknown error';
    }
  }
  
  /// Get the error title for failed imports
  String? get errorTitle {
    if (type == ImportResultType.failed && errorCategory != null) {
      return ImportErrorHelper.getErrorTitle(errorCategory!);
    }
    return null;
  }
  
  /// Get the error icon for failed imports
  String? get errorIcon {
    if (type == ImportResultType.failed && errorCategory != null) {
      return ImportErrorHelper.getErrorIcon(errorCategory!);
    }
    return null;
  }

  /// Format the flight info for display
  String get flightInfo {
    if (flightDate == null || flightTime == null) return '';
    return '${_formatDate(flightDate!)} ${flightTime!}${duration != null ? ' (${duration}min)' : ''}';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// Summary of all import results
class ImportSummary {
  final List<ImportResult> results;

  ImportSummary(this.results);

  int get totalFiles => results.length;
  int get importedCount => results.where((r) => r.type == ImportResultType.imported).length;
  int get replacedCount => results.where((r) => r.type == ImportResultType.replaced).length;
  int get skippedCount => results.where((r) => r.type == ImportResultType.skipped).length;
  int get failedCount => results.where((r) => r.type == ImportResultType.failed).length;
  int get successCount => importedCount + replacedCount;

  List<ImportResult> get imported => results.where((r) => r.type == ImportResultType.imported).toList();
  List<ImportResult> get replaced => results.where((r) => r.type == ImportResultType.replaced).toList();
  List<ImportResult> get skipped => results.where((r) => r.type == ImportResultType.skipped).toList();
  List<ImportResult> get failed => results.where((r) => r.type == ImportResultType.failed).toList();

  /// Get a summary message for display
  String get summaryMessage {
    final parts = <String>[];
    
    if (importedCount > 0) {
      parts.add('$importedCount imported');
    }
    if (replacedCount > 0) {
      parts.add('$replacedCount replaced');
    }
    if (skippedCount > 0) {
      parts.add('$skippedCount skipped');
    }
    if (failedCount > 0) {
      parts.add('$failedCount failed');
    }

    if (parts.isEmpty) {
      return 'No files processed';
    }

    return parts.join(', ');
  }
}