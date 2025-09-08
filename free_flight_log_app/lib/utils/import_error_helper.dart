/// Categories of errors that can occur during IGC import
enum ImportErrorCategory {
  fileAccess,        // File not found, permission denied
  parseError,        // Invalid IGC format, missing required data
  dataValidation,    // No track points, invalid dates/times
  databaseError,     // Storage issues, corruption
  memoryError,       // File too large, insufficient memory
  networkError,      // For future online features
  unknown,           // Uncategorized errors
}

/// Helper class for categorizing import errors and providing user-friendly messages
class ImportErrorHelper {
  /// Categorize an error based on its type and message
  static ImportErrorCategory categorizeError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // File access errors
    if (errorString.contains('file not found') ||
        errorString.contains('no such file') ||
        errorString.contains('cannot open file') ||
        errorString.contains('permission denied') ||
        errorString.contains('access denied')) {
      return ImportErrorCategory.fileAccess;
    }
    
    // Parse errors
    if (errorString.contains('invalid format') ||
        errorString.contains('missing header') ||
        errorString.contains('malformed') ||
        errorString.contains('parse') ||
        errorString.contains('format')) {
      return ImportErrorCategory.parseError;
    }
    
    // Data validation errors
    if (errorString.contains('no track points') ||
        errorString.contains('empty track') ||
        errorString.contains('no gps data') ||
        errorString.contains('invalid date') ||
        errorString.contains('invalid time') ||
        errorString.contains('no flight data')) {
      return ImportErrorCategory.dataValidation;
    }
    
    // Database errors
    if (errorString.contains('database') ||
        errorString.contains('sql') ||
        errorString.contains('storage') ||
        errorString.contains('corrupt')) {
      return ImportErrorCategory.databaseError;
    }
    
    // Memory errors
    if (errorString.contains('out of memory') ||
        errorString.contains('memory') ||
        errorString.contains('too large') ||
        errorString.contains('insufficient space')) {
      return ImportErrorCategory.memoryError;
    }
    
    // Network errors (for future use)
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('unreachable')) {
      return ImportErrorCategory.networkError;
    }
    
    return ImportErrorCategory.unknown;
  }
  
  /// Get a user-friendly error message with suggested solutions
  static String getUserFriendlyMessage(dynamic error, ImportErrorCategory category) {
    switch (category) {
      case ImportErrorCategory.fileAccess:
        return _getFileAccessMessage(error);
      case ImportErrorCategory.parseError:
        return _getParseErrorMessage(error);
      case ImportErrorCategory.dataValidation:
        return _getDataValidationMessage(error);
      case ImportErrorCategory.databaseError:
        return _getDatabaseErrorMessage(error);
      case ImportErrorCategory.memoryError:
        return _getMemoryErrorMessage(error);
      case ImportErrorCategory.networkError:
        return _getNetworkErrorMessage(error);
      case ImportErrorCategory.unknown:
        return _getUnknownErrorMessage(error);
    }
  }
  
  /// Get a complete error result with category and user-friendly message
  static ({ImportErrorCategory category, String message}) processError(dynamic error) {
    final category = categorizeError(error);
    final message = getUserFriendlyMessage(error, category);
    return (category: category, message: message);
  }
  
  static String _getFileAccessMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('file not found') || errorString.contains('no such file')) {
      return 'File not found: The IGC file may have been moved or deleted. Please select the file again.';
    }
    
    if (errorString.contains('permission denied') || errorString.contains('access denied')) {
      return 'Permission denied: Cannot access the file. Check that you have permission to read the file and try again.';
    }
    
    return 'Cannot access file: The file may have been moved, deleted, or you may not have permission to read it. Please try selecting the file again.';
  }
  
  static String _getParseErrorMessage(dynamic error) {
    return 'Invalid IGC file format: The file appears to be corrupted or is not a valid IGC file. Please check that you selected the correct file, or try downloading it again from your flight recorder.';
  }
  
  static String _getDataValidationMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('no track points') || errorString.contains('empty track')) {
      return 'No flight data found: The IGC file contains no GPS track points. The file may be incomplete or corrupted. Try downloading the flight data again from your instrument.';
    }
    
    if (errorString.contains('invalid date') || errorString.contains('invalid time')) {
      return 'Invalid flight date/time: The IGC file contains invalid date or time information. Please check your flight recorder\'s date and time settings.';
    }
    
    return 'Invalid flight data: The IGC file contains incomplete or invalid flight information. Please verify the file is complete and try again.';
  }
  
  static String _getDatabaseErrorMessage(dynamic error) {
    return 'Database error: There was a problem saving the flight data. Please try again, and if the problem persists, consider restarting the app.';
  }
  
  static String _getMemoryErrorMessage(dynamic error) {
    return 'File too large: The IGC file is too large to process. Try importing smaller flight files, or restart the app and try again.';
  }
  
  static String _getNetworkErrorMessage(dynamic error) {
    return 'Network error: Cannot connect to online services. Please check your internet connection and try again.';
  }
  
  static String _getUnknownErrorMessage(dynamic error) {
    // For unknown errors, still provide some guidance but include the original error
    final errorString = error.toString();
    return 'Unexpected error: $errorString\n\nPlease try again, and if the problem persists, consider restarting the app or selecting a different file.';
  }
  
  /// Get an icon that represents the error category
  static String getErrorIcon(ImportErrorCategory category) {
    switch (category) {
      case ImportErrorCategory.fileAccess:
        return '📁';
      case ImportErrorCategory.parseError:
        return '📄';
      case ImportErrorCategory.dataValidation:
        return '📊';
      case ImportErrorCategory.databaseError:
        return '💾';
      case ImportErrorCategory.memoryError:
        return '🧠';
      case ImportErrorCategory.networkError:
        return '🌐';
      case ImportErrorCategory.unknown:
        return '❓';
    }
  }
  
  /// Get a short title for the error category
  static String getErrorTitle(ImportErrorCategory category) {
    switch (category) {
      case ImportErrorCategory.fileAccess:
        return 'File Access Problem';
      case ImportErrorCategory.parseError:
        return 'Invalid File Format';
      case ImportErrorCategory.dataValidation:
        return 'Invalid Flight Data';
      case ImportErrorCategory.databaseError:
        return 'Database Error';
      case ImportErrorCategory.memoryError:
        return 'Memory Error';
      case ImportErrorCategory.networkError:
        return 'Network Error';
      case ImportErrorCategory.unknown:
        return 'Unexpected Error';
    }
  }
}