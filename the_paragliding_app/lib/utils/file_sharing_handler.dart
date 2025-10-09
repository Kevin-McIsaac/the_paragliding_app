import 'dart:async';
import 'dart:io' show Platform;

// Conditional imports for platform-specific implementations
import 'file_sharing_handler_stub.dart'
    if (dart.library.io) 'file_sharing_handler_mobile.dart';

/// Handles incoming file sharing intents in a platform-aware way
class FileSharingHandler {
  static StreamSubscription? _subscription;
  
  /// Initialize file sharing handler and return initial shared files
  static Future<List<String>?> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }
    
    return await getInitialSharedFiles();
  }
  
  /// Listen for incoming shared files
  static StreamSubscription? listen(Function(List<String>) onFilesReceived) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }
    
    return listenForSharedFiles(onFilesReceived);
  }
  
  /// Cancel the subscription
  static void dispose() {
    _subscription?.cancel();
  }
}