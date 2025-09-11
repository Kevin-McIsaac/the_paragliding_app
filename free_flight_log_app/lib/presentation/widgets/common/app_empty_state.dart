import 'package:flutter/material.dart';

/// A reusable widget for displaying empty states with consistent styling.
/// 
/// Used across FlightListScreen, WingManagementScreen, StatisticsScreen, and other screens
/// that need to display empty state messages with optional action buttons.
class AppEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionButtonText;
  final IconData? actionButtonIcon;
  final Color? iconColor;
  final double? iconSize;
  final EdgeInsets? padding;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;

  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.onAction,
    this.actionButtonText,
    this.actionButtonIcon,
    this.iconColor,
    this.iconSize,
    this.padding,
    this.mainAxisAlignment = MainAxisAlignment.center,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  /// Factory for creating an empty flights state
  factory AppEmptyState.flights({
    VoidCallback? onAddFlight,
  }) {
    return AppEmptyState(
      title: 'No flights recorded yet',
      message: 'Tap the + button to log your first flight',
      icon: Icons.flight_takeoff,
      onAction: onAddFlight,
      actionButtonText: 'Add Flight',
      actionButtonIcon: Icons.add,
    );
  }

  /// Factory for creating an empty wings state
  factory AppEmptyState.wings({
    VoidCallback? onAddWing,
  }) {
    return AppEmptyState(
      title: 'No wings found',
      message: 'Add your first wing to get started',
      icon: Icons.paragliding,
      onAction: onAddWing,
      actionButtonText: 'Add Wing',
      actionButtonIcon: Icons.add,
    );
  }

  /// Factory for creating an empty sites state
  factory AppEmptyState.sites({
    VoidCallback? onAddSite,
  }) {
    return AppEmptyState(
      title: 'No sites found',
      message: 'Add your first flying site to get started',
      icon: Icons.location_on,
      onAction: onAddSite,
      actionButtonText: 'Add Site',
      actionButtonIcon: Icons.add,
    );
  }

  /// Factory for creating an empty statistics state
  factory AppEmptyState.statistics({
    VoidCallback? onAddFlight,
  }) {
    return AppEmptyState(
      title: 'No flight data yet',
      message: 'Statistics will appear once you log some flights',
      icon: Icons.bar_chart,
      onAction: onAddFlight,
      actionButtonText: 'Add Flight',
      actionButtonIcon: Icons.add,
    );
  }

  /// Factory for creating an empty search results state
  factory AppEmptyState.searchResults({
    String? searchTerm,
    VoidCallback? onClearSearch,
  }) {
    return AppEmptyState(
      title: 'No results found',
      message: searchTerm != null 
          ? 'No items match "$searchTerm"'
          : 'Try adjusting your search criteria',
      icon: Icons.search_off,
      onAction: onClearSearch,
      actionButtonText: 'Clear Search',
      actionButtonIcon: Icons.clear,
    );
  }

  /// Factory for creating a generic empty state
  factory AppEmptyState.generic({
    required String title,
    required String message,
    required IconData icon,
    VoidCallback? onAction,
    String? actionButtonText,
    IconData? actionButtonIcon,
  }) {
    return AppEmptyState(
      title: title,
      message: message,
      icon: icon,
      onAction: onAction,
      actionButtonText: actionButtonText,
      actionButtonIcon: actionButtonIcon,
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
            icon,
            size: iconSize ?? 64,
            color: iconColor ?? Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
          if (onAction != null) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: actionButtonIcon != null 
                  ? Icon(actionButtonIcon) 
                  : const SizedBox.shrink(),
              label: Text(actionButtonText ?? 'Get Started'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact empty state widget for smaller spaces (e.g., within cards or sections)
class AppCompactEmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionText;
  final Color? iconColor;
  final double iconSize;
  final EdgeInsets? padding;

  const AppCompactEmptyState({
    super.key,
    required this.message,
    required this.icon,
    this.onAction,
    this.actionText,
    this.iconColor,
    this.iconSize = 32,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: padding ?? const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: iconSize,
            color: iconColor ?? Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          if (onAction != null && actionText != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAction,
              child: Text(
                actionText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// An empty state widget specifically for list views with placeholder content
class AppListEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionText;
  final Widget? customAction;
  final EdgeInsets? margin;

  const AppListEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.onAction,
    this.actionText,
    this.customAction,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 32,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (customAction != null) ...[
            const SizedBox(height: 16),
            customAction!,
          ] else if (onAction != null && actionText != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onAction,
              child: Text(actionText!),
            ),
          ],
        ],
      ),
    );
  }
}