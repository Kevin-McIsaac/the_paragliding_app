import 'package:logger/logger.dart';

/// Custom log printer optimized for Claude Code readability
/// Provides structured, parseable output with file locations
class ClaudeLogPrinter extends LogPrinter {
  static final _startTime = DateTime.now();
  static const _levelPrefixes = {
    Level.debug: 'D',
    Level.info: 'I',
    Level.warning: 'W',
    Level.error: 'E',
    Level.fatal: 'F',
  };

  @override
  List<String> log(LogEvent event) {
    final level = _levelPrefixes[event.level] ?? 'U';
    final elapsed = DateTime.now().difference(_startTime);
    final timeStr = _formatElapsedTime(elapsed);
    
    // Extract location from stack trace if available
    final location = _extractLocation(event.stackTrace ?? StackTrace.current);
    
    // Format the message with structure
    final message = _formatMessage(event.message, location);
    
    // Add error information if present
    if (event.error != null) {
      return ['[$level][$timeStr] $message | error=${event.error}'];
    }
    
    return ['[$level][$timeStr] $message'];
  }

  String _formatElapsedTime(Duration elapsed) {
    if (elapsed.inSeconds < 60) {
      return '+${elapsed.inSeconds}.${(elapsed.inMilliseconds % 1000).toString().padLeft(3, '0')}s';
    } else if (elapsed.inMinutes < 60) {
      return '+${elapsed.inMinutes}m${(elapsed.inSeconds % 60)}s';
    } else {
      return '+${elapsed.inHours}h${(elapsed.inMinutes % 60)}m';
    }
  }

  String _extractLocation(StackTrace stackTrace) {
    final lines = stackTrace.toString().split('\n');
    
    // Skip logger internal frames and find the actual caller
    for (final line in lines) {
      // Skip logger internals
      if (line.contains('logger.dart') || 
          line.contains('logging_service.dart') ||
          line.contains('claude_log_printer.dart')) {
        continue;
      }
      
      // Extract file and line from stack frame
      // Format: #N   ClassName.method (package:app/path/file.dart:line:col)
      final match = RegExp(r'\(package:[^/]+/(.+\.dart):(\d+)').firstMatch(line);
      if (match != null) {
        final file = match.group(1)!.split('/').last; // Just filename
        final lineNum = match.group(2)!;
        return '$file:$lineNum';
      }
    }
    
    return '';
  }

  String _formatMessage(dynamic message, String location) {
    final msg = message.toString();
    
    // Add location if available
    if (location.isNotEmpty) {
      // Check if message already has structure
      if (msg.startsWith('[') && msg.contains(']')) {
        // Message already has category, append location
        return '$msg | at=$location';
      } else {
        // Plain message, add location
        return '$msg | at=$location';
      }
    }
    
    return msg;
  }
}