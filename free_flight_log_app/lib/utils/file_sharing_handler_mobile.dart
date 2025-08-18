import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Mobile implementation for handling shared files
Future<List<String>?> getInitialSharedFiles() async {
  // Use the correct API method for the package
  final files = await ReceiveSharingIntent.instance.getInitialMedia();
  if (files == null || files.isEmpty) return null;
  
  return files
      .where((file) => file.path != null && file.path!.toLowerCase().endsWith('.igc'))
      .map((file) => file.path!)
      .toList();
}

StreamSubscription? listenForSharedFiles(Function(List<String>) onFilesReceived) {
  // Use the correct API method for the package
  return ReceiveSharingIntent.instance.getMediaStream().listen(
    (List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final igcFiles = value
            .where((file) => file.path != null && file.path!.toLowerCase().endsWith('.igc'))
            .map((file) => file.path!)
            .toList();
        if (igcFiles.isNotEmpty) {
          onFilesReceived(igcFiles);
        }
      }
    },
    onError: (err) {
      print("Error receiving shared files: $err");
    },
  );
}