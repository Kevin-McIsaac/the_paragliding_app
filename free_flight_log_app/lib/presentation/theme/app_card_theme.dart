import 'package:flutter/material.dart';

/// Centralized constants for card styling throughout the app.
/// 
/// Provides consistent elevation, padding, margins, and other styling
/// properties used across all card-based widgets.
class AppCardTheme {
  // Private constructor to prevent instantiation
  AppCardTheme._();

  // MARK: - Elevation Constants
  
  /// Standard elevation for most cards
  static const double defaultElevation = 2.0;
  
  /// Lower elevation for subtle cards
  static const double lowElevation = 1.0;
  
  /// Higher elevation for important/prominent cards
  static const double highElevation = 4.0;
  
  /// No elevation for flat cards
  static const double noElevation = 0.0;

  // MARK: - Padding Constants
  
  /// Standard padding for card content
  static const EdgeInsets defaultPadding = EdgeInsets.all(16.0);
  
  /// Compact padding for smaller cards
  static const EdgeInsets compactPadding = EdgeInsets.all(12.0);
  
  /// Generous padding for spacious cards
  static const EdgeInsets generousPadding = EdgeInsets.all(20.0);
  
  /// Horizontal padding only
  static const EdgeInsets horizontalPadding = EdgeInsets.symmetric(horizontal: 16.0);
  
  /// Vertical padding only
  static const EdgeInsets verticalPadding = EdgeInsets.symmetric(vertical: 16.0);
  
  /// Asymmetric padding for specific cases
  static const EdgeInsets asymmetricPadding = EdgeInsets.fromLTRB(16, 0, 16, 16);

  // MARK: - Margin Constants
  
  /// Standard margin between cards
  static const EdgeInsets defaultMargin = EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0);
  
  /// Compact margin for dense layouts
  static const EdgeInsets compactMargin = EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0);
  
  /// Generous margin for spacious layouts
  static const EdgeInsets generousMargin = EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
  
  /// Bottom-only margin
  static const EdgeInsets bottomMargin = EdgeInsets.only(bottom: 16.0);
  
  /// Section margin (larger vertical spacing)
  static const EdgeInsets sectionMargin = EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0);

  // MARK: - Border Radius Constants
  
  /// Standard border radius for cards
  static const double defaultBorderRadius = 8.0;
  
  /// Small border radius for subtle rounding
  static const double smallBorderRadius = 4.0;
  
  /// Large border radius for prominent cards
  static const double largeBorderRadius = 12.0;
  
  /// Circular border radius
  static const double circularBorderRadius = 50.0;

  // MARK: - Spacing Constants
  
  /// Small spacing between elements
  static const double smallSpacing = 8.0;
  
  /// Default spacing between elements
  static const double defaultSpacing = 16.0;
  
  /// Large spacing between sections
  static const double largeSpacing = 24.0;
  
  /// Extra large spacing for major sections
  static const double extraLargeSpacing = 32.0;

  // MARK: - Icon Sizes
  
  /// Small icon size
  static const double smallIconSize = 16.0;
  
  /// Default icon size
  static const double defaultIconSize = 24.0;
  
  /// Large icon size
  static const double largeIconSize = 32.0;
  
  /// Extra large icon size for empty states
  static const double extraLargeIconSize = 64.0;

  // MARK: - Text Spacing
  
  /// Spacing between title and subtitle
  static const double titleSubtitleSpacing = 4.0;
  
  /// Spacing between label and value
  static const double labelValueSpacing = 8.0;
  
  /// Spacing between rows in lists
  static const double rowSpacing = 12.0;

  // MARK: - Border Width Constants
  
  /// Thin border width
  static const double thinBorderWidth = 1.0;
  
  /// Standard border width
  static const double defaultBorderWidth = 2.0;
  
  /// Thick border width
  static const double thickBorderWidth = 3.0;

  // MARK: - Component-Specific Themes
  
  /// Theme for stat cards
  static const StatCardTheme statCard = StatCardTheme();
  
  /// Theme for expansion cards
  static const ExpansionCardTheme expansionCard = ExpansionCardTheme();
  
  /// Theme for list cards
  static const ListCardTheme listCard = ListCardTheme();
  
  /// Theme for error states
  static const ErrorStateTheme errorState = ErrorStateTheme();
  
  /// Theme for empty states
  static const EmptyStateTheme emptyState = EmptyStateTheme();
}

/// Specific theme constants for stat cards
class StatCardTheme {
  const StatCardTheme();
  
  EdgeInsets get padding => AppCardTheme.defaultPadding;
  EdgeInsets get margin => AppCardTheme.compactMargin;
  double get elevation => AppCardTheme.defaultElevation;
  double get borderRadius => AppCardTheme.defaultBorderRadius;
  double get iconSize => AppCardTheme.defaultIconSize;
  double get spacing => AppCardTheme.labelValueSpacing;
}

/// Specific theme constants for expansion cards
class ExpansionCardTheme {
  const ExpansionCardTheme();
  
  EdgeInsets get padding => AppCardTheme.defaultPadding;
  EdgeInsets get margin => AppCardTheme.defaultMargin;
  double get elevation => AppCardTheme.defaultElevation;
  double get borderRadius => AppCardTheme.defaultBorderRadius;
  double get iconSize => AppCardTheme.defaultIconSize;
  double get sectionSpacing => AppCardTheme.largeSpacing;
}

/// Specific theme constants for list cards
class ListCardTheme {
  const ListCardTheme();
  
  EdgeInsets get padding => AppCardTheme.defaultPadding;
  EdgeInsets get margin => AppCardTheme.defaultMargin;
  double get elevation => AppCardTheme.defaultElevation;
  double get borderRadius => AppCardTheme.defaultBorderRadius;
  double get iconSize => AppCardTheme.defaultIconSize;
  double get itemSpacing => AppCardTheme.rowSpacing;
}

/// Specific theme constants for error states
class ErrorStateTheme {
  const ErrorStateTheme();
  
  EdgeInsets get padding => AppCardTheme.defaultPadding;
  double get iconSize => AppCardTheme.extraLargeIconSize;
  double get spacing => AppCardTheme.defaultSpacing;
  double get borderRadius => AppCardTheme.defaultBorderRadius;
}

/// Specific theme constants for empty states
class EmptyStateTheme {
  const EmptyStateTheme();
  
  EdgeInsets get padding => AppCardTheme.defaultPadding;
  double get iconSize => AppCardTheme.extraLargeIconSize;
  double get spacing => AppCardTheme.defaultSpacing;
  double get borderRadius => AppCardTheme.defaultBorderRadius;
}

/// Helper extension for accessing theme constants in a type-safe way
extension AppCardThemeExtension on BuildContext {
  /// Get the current card theme
  AppCardThemeData get cardTheme => AppCardThemeData.of(this);
}

/// Runtime theme data that adapts to the current Flutter theme
class AppCardThemeData {
  final ThemeData theme;
  
  const AppCardThemeData(this.theme);
  
  factory AppCardThemeData.of(BuildContext context) {
    return AppCardThemeData(Theme.of(context));
  }
  
  // MARK: - Color Getters
  
  Color get primaryColor => theme.colorScheme.primary;
  Color get onPrimaryColor => theme.colorScheme.onPrimary;
  Color get surfaceColor => theme.colorScheme.surface;
  Color get onSurfaceColor => theme.colorScheme.onSurface;
  Color get errorColor => theme.colorScheme.error;
  Color get onErrorColor => theme.colorScheme.onError;
  
  // Container colors
  Color get primaryContainer => theme.colorScheme.primaryContainer;
  Color get onPrimaryContainer => theme.colorScheme.onPrimaryContainer;
  Color get errorContainer => theme.colorScheme.errorContainer;
  Color get onErrorContainer => theme.colorScheme.onErrorContainer;
  
  // Variant colors
  Color get onSurfaceVariant => theme.colorScheme.onSurfaceVariant;
  Color get outline => theme.colorScheme.outline;
  
  // Computed colors for specific states
  Color get errorIconColor => theme.brightness == Brightness.light
      ? const Color(0xFFD32F2F) // Red 700
      : const Color(0xFFEF5350); // Red 400
      
  Color get emptyIconColor => theme.brightness == Brightness.light
      ? const Color(0xFF9E9E9E) // Grey 500
      : const Color(0xFF757575); // Grey 600
      
  Color get disabledColor => theme.disabledColor;
  Color get dividerColor => theme.dividerColor;
  
  // MARK: - Text Style Getters
  
  TextStyle? get headlineSmall => theme.textTheme.headlineSmall;
  TextStyle? get headlineMedium => theme.textTheme.headlineMedium;
  TextStyle? get titleLarge => theme.textTheme.titleLarge;
  TextStyle? get titleMedium => theme.textTheme.titleMedium;
  TextStyle? get titleSmall => theme.textTheme.titleSmall;
  TextStyle? get bodyLarge => theme.textTheme.bodyLarge;
  TextStyle? get bodyMedium => theme.textTheme.bodyMedium;
  TextStyle? get bodySmall => theme.textTheme.bodySmall;
  TextStyle? get labelLarge => theme.textTheme.labelLarge;
  TextStyle? get labelMedium => theme.textTheme.labelMedium;
  TextStyle? get labelSmall => theme.textTheme.labelSmall;
}