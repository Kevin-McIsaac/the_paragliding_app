import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../services/logging_service.dart';

/// User Manual screen that displays the formatted user guide using Markdown.
///
/// Loads the user manual from assets and renders it with flutter_markdown_plus.
/// Supports scrolling, text selection, and follows Material Design 3 theming.
class UserManualScreen extends StatefulWidget {
  const UserManualScreen({super.key});

  @override
  State<UserManualScreen> createState() => _UserManualScreenState();
}

class _UserManualScreenState extends State<UserManualScreen> {
  String _markdownContent = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserManual();
  }

  Future<void> _loadUserManual() async {
    try {
      final content = await rootBundle.loadString('assets/documentation/user_manual.md');
      setState(() {
        _markdownContent = content;
        _isLoading = false;
      });
      LoggingService.info('UserManualScreen: User manual loaded successfully');
    } catch (e, stackTrace) {
      LoggingService.error('UserManualScreen: Failed to load user manual', e, stackTrace);
      setState(() {
        _errorMessage = 'Failed to load user manual: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Manual'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _loadUserManual();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Markdown(
      data: _markdownContent,
      selectable: true,
      padding: const EdgeInsets.all(16.0),
      styleSheet: MarkdownStyleSheet(
        // Use theme colors for better Material Design 3 integration
        h1: Theme.of(context).textTheme.headlineLarge,
        h2: Theme.of(context).textTheme.headlineMedium,
        h3: Theme.of(context).textTheme.headlineSmall,
        h4: Theme.of(context).textTheme.titleLarge,
        h5: Theme.of(context).textTheme.titleMedium,
        h6: Theme.of(context).textTheme.titleSmall,
        p: Theme.of(context).textTheme.bodyLarge,
        code: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
        blockSpacing: 12.0,
        listIndent: 24.0,
      ),
    );
  }
}
