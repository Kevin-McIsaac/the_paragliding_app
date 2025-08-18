import 'dart:async';

/// Stub implementation for platforms that don't support file sharing
Future<List<String>?> getInitialSharedFiles() async {
  return null;
}

StreamSubscription? listenForSharedFiles(Function(List<String>) onFilesReceived) {
  return null;
}