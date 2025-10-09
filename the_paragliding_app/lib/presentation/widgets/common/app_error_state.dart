import 'package:flutter/material.dart';

/// A reusable widget for displaying error states with consistent styling.
/// 
/// Used across FlightListScreen, WingManagementScreen, StatisticsScreen, and other screens
/// that need to display error messages with retry functionality.
class AppErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String? retryButtonText;
  final IconData? icon;
  final Color? iconColor;
  final double? iconSize;
  final EdgeInsets? padding;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;

  const AppErrorState({
    super.key,
    this.title = 'Error',
    required this.message,
    this.onRetry,
    this.retryButtonText,
    this.icon,
    this.iconColor,
    this.iconSize,
    this.padding,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  /// Factory for creating a loading error state (used when data fails to load)
  factory AppErrorState.loading({
    required String message,
    VoidCallback? onRetry,
    String? retryButtonText,
  }) {
    return AppErrorState(
      title: 'Error loading data',
      message: message,
      onRetry: onRetry,
      retryButtonText: retryButtonText ?? 'Retry',
      icon: Icons.error_outline,
    );
  }

  /// Factory for creating a network error state
  factory AppErrorState.network({
    String? message,
    VoidCallback? onRetry,
    String? retryButtonText,
  }) {
    return AppErrorState(
      title: 'Connection Error',
      message: message ?? 'Check your internet connection and try again',
      onRetry: onRetry,
      retryButtonText: retryButtonText ?? 'Retry',
      icon: Icons.wifi_off,
    );
  }

  /// Factory for creating a generic error state with custom icon
  factory AppErrorState.generic({
    String? title,
    required String message,
    VoidCallback? onRetry,
    String? retryButtonText,
    IconData? icon,
  }) {
    return AppErrorState(
      title: title ?? 'Something went wrong',
      message: message,
      onRetry: onRetry,
      retryButtonText: retryButtonText ?? 'Try Again',
      icon: icon ?? Icons.error,
    );
  }

  /// Factory for creating a validation error state (no retry button)
  factory AppErrorState.validation({
    String? title,
    required String message,
    IconData? icon,
  }) {
    return AppErrorState(
      title: title ?? 'Invalid Input',
      message: message,
      icon: icon ?? Icons.warning,
      iconColor: Colors.orange,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Icon(
            icon ?? Icons.error,
            size: iconSize ?? 64,
            color: iconColor ?? Colors.red[400],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: Text(retryButtonText ?? 'Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact error widget for inline error display (e.g., within cards or forms)
class AppInlineError extends StatelessWidget {
  final String message;
  final IconData? icon;
  final Color? iconColor;
  final Color? backgroundColor;
  final EdgeInsets? padding;
  final VoidCallback? onDismiss;

  const AppInlineError({
    super.key,
    required this.message,
    this.icon,
    this.iconColor,
    this.backgroundColor,
    this.padding,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.red.shade200,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon ?? Icons.warning,
            size: 20,
            color: iconColor ?? Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.red.shade700,
              ),
            ),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onDismiss,
              child: Icon(
                Icons.close,
                size: 18,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// An error banner for displaying errors at the top of a screen or section
class AppErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;
  final String? retryText;
  final Color? backgroundColor;
  final Color? textColor;

  const AppErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.onDismiss,
    this.retryText,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: backgroundColor ?? Colors.red.shade100,
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: textColor ?? Colors.red.shade700,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor ?? Colors.red.shade700,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              child: Text(
                retryText ?? 'Retry',
                style: TextStyle(
                  color: textColor ?? Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (onDismiss != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onDismiss,
              child: Icon(
                Icons.close,
                color: textColor ?? Colors.red.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}