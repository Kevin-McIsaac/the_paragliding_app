import 'package:flutter/material.dart';

/// A reusable widget for displaying statistics with consistent styling.
/// 
/// Supports both vertical (stacked) and horizontal (side-by-side) layouts.
/// Used across FlightListScreen, DataManagementScreen, and other screens
/// that need to display key-value statistics.
class AppStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final Color? labelColor;
  final TextStyle? valueTextStyle;
  final TextStyle? labelTextStyle;
  final EdgeInsets? padding;
  final bool isHorizontal;
  final CrossAxisAlignment alignment;
  final MainAxisAlignment mainAxisAlignment;

  const AppStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.labelColor,
    this.valueTextStyle,
    this.labelTextStyle,
    this.padding,
    this.isHorizontal = false,
    this.alignment = CrossAxisAlignment.center,
    this.mainAxisAlignment = MainAxisAlignment.center,
  });

  /// Factory for creating a stat card used in flight lists (vertical layout)
  factory AppStatCard.flightList({
    required String label,
    required String value,
    IconData? icon,
  }) {
    return AppStatCard(
      label: label,
      value: value,
      icon: icon,
      isHorizontal: false,
      alignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
    );
  }

  /// Factory for creating a stat row used in data management (horizontal layout)
  factory AppStatCard.dataRow({
    required String label,
    required String value,
    IconData? icon,
  }) {
    return AppStatCard(
      label: label,
      value: value,
      icon: icon,
      isHorizontal: true,
      alignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      padding: const EdgeInsets.symmetric(vertical: 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Default text styles based on layout
    final defaultValueStyle = isHorizontal
        ? theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: valueColor,
          )
        : theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor ?? theme.colorScheme.primary,
          );
    
    final defaultLabelStyle = isHorizontal
        ? theme.textTheme.bodyMedium?.copyWith(
            color: labelColor ?? theme.colorScheme.onSurfaceVariant,
          )
        : theme.textTheme.bodySmall?.copyWith(
            color: labelColor ?? Colors.grey[600],
          );

    Widget content = isHorizontal ? _buildHorizontalLayout(
      theme,
      defaultValueStyle,
      defaultLabelStyle,
    ) : _buildVerticalLayout(
      theme,
      defaultValueStyle,
      defaultLabelStyle,
    );

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: content,
    );
  }

  Widget _buildVerticalLayout(
    ThemeData theme,
    TextStyle? defaultValueStyle,
    TextStyle? defaultLabelStyle,
  ) {
    return Column(
      crossAxisAlignment: alignment,
      mainAxisAlignment: mainAxisAlignment,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 24,
            color: valueColor ?? theme.colorScheme.primary,
          ),
          const SizedBox(height: 8),
        ],
        Text(
          value,
          textAlign: TextAlign.center,
          style: valueTextStyle ?? defaultValueStyle,
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: labelTextStyle ?? defaultLabelStyle,
        ),
      ],
    );
  }

  Widget _buildHorizontalLayout(
    ThemeData theme,
    TextStyle? defaultValueStyle,
    TextStyle? defaultLabelStyle,
  ) {
    return Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: alignment,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: labelColor ?? theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            label,
            style: labelTextStyle ?? defaultLabelStyle,
          ),
        ),
        Text(
          value,
          style: valueTextStyle ?? defaultValueStyle,
        ),
      ],
    );
  }
}

/// A container widget that wraps multiple AppStatCards with consistent spacing.
/// Useful for creating stat card groups in different layouts.
class AppStatCardGroup extends StatelessWidget {
  final List<AppStatCard> cards;
  final bool isHorizontal;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final double spacing;

  const AppStatCardGroup({
    super.key,
    required this.cards,
    this.isHorizontal = true,
    this.padding,
    this.backgroundColor,
    this.spacing = 16.0,
  });

  /// Factory for creating a flight list stat group (horizontal layout)
  factory AppStatCardGroup.flightList({
    required List<AppStatCard> cards,
    EdgeInsets? padding,
    Color? backgroundColor,
  }) {
    return AppStatCardGroup(
      cards: cards,
      isHorizontal: true,
      padding: padding ?? const EdgeInsets.symmetric(vertical: 16),
      backgroundColor: backgroundColor,
      spacing: 0, // Cards handle their own spacing in flight list
    );
  }

  /// Factory for creating a data management stat group (vertical layout)
  factory AppStatCardGroup.dataManagement({
    required List<AppStatCard> cards,
    EdgeInsets? padding,
  }) {
    return AppStatCardGroup(
      cards: cards,
      isHorizontal: false,
      padding: padding ?? const EdgeInsets.all(16),
      spacing: 8.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Widget content = isHorizontal
        ? Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: cards.map((card) => Expanded(child: card)).toList(),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cards
                .expand((card) => [card, if (card != cards.last) SizedBox(height: spacing)])
                .toList(),
          );

    if (backgroundColor != null || padding != null) {
      content = Container(
        padding: padding,
        color: backgroundColor ?? theme.colorScheme.surface,
        child: content,
      );
    }

    return content;
  }
}