import 'package:flutter/material.dart';
import '../../theme/app_card_theme.dart';

/// A reusable widget for displaying label-value pairs in a horizontal row.
/// 
/// Used throughout the app for consistent display of statistics, properties,
/// and other key-value information in cards and lists.
class AppStatRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? labelColor;
  final Color? valueColor;
  final Color? iconColor;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final EdgeInsets? padding;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final double? iconSize;
  final Widget? trailing;

  const AppStatRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.labelColor,
    this.valueColor,
    this.iconColor,
    this.labelStyle,
    this.valueStyle,
    this.padding,
    this.mainAxisAlignment = MainAxisAlignment.spaceBetween,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.iconSize,
    this.trailing,
  });

  /// Factory for creating a data management stat row with standard styling
  factory AppStatRow.dataManagement({
    required String label,
    required String value,
    IconData? icon,
    Widget? trailing,
  }) {
    return AppStatRow(
      label: label,
      value: value,
      icon: icon,
      trailing: trailing,
      padding: const EdgeInsets.symmetric(vertical: 8),
    );
  }

  /// Factory for creating a compact stat row (less padding)
  factory AppStatRow.compact({
    required String label,
    required String value,
    IconData? icon,
    Widget? trailing,
  }) {
    return AppStatRow(
      label: label,
      value: value,
      icon: icon,
      trailing: trailing,
      padding: const EdgeInsets.symmetric(vertical: 4),
    );
  }

  /// Factory for creating a prominent stat row (larger text)
  factory AppStatRow.prominent({
    required String label,
    required String value,
    IconData? icon,
    Widget? trailing,
  }) {
    return AppStatRow(
      label: label,
      value: value,
      icon: icon,
      trailing: trailing,
      padding: const EdgeInsets.symmetric(vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardTheme = AppCardThemeData.of(context);
    
    // Default text styles
    final defaultLabelStyle = labelStyle ?? theme.textTheme.bodyMedium?.copyWith(
      color: labelColor ?? cardTheme.onSurfaceVariant,
    );
    
    final defaultValueStyle = valueStyle ?? theme.textTheme.bodyLarge?.copyWith(
      color: valueColor ?? cardTheme.onSurfaceColor,
      fontWeight: FontWeight.w500,
    );

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Row(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          // Icon (optional)
          if (icon != null) ...[
            Icon(
              icon,
              size: iconSize ?? AppCardTheme.smallIconSize,
              color: iconColor ?? cardTheme.onSurfaceVariant,
            ),
            SizedBox(width: AppCardTheme.smallSpacing),
          ],
          
          // Label
          Expanded(
            child: Text(
              label,
              style: defaultLabelStyle,
            ),
          ),
          
          // Value
          Text(
            value,
            style: defaultValueStyle,
          ),
          
          // Trailing widget (optional)
          if (trailing != null) ...[
            SizedBox(width: AppCardTheme.smallSpacing),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A group of stat rows with consistent spacing and optional dividers
class AppStatRowGroup extends StatelessWidget {
  final List<AppStatRow> rows;
  final bool showDividers;
  final EdgeInsets? padding;
  final Color? dividerColor;
  final double spacing;

  const AppStatRowGroup({
    super.key,
    required this.rows,
    this.showDividers = false,
    this.padding,
    this.dividerColor,
    this.spacing = 0,
  });

  /// Factory for creating a data management stat group
  factory AppStatRowGroup.dataManagement({
    required List<AppStatRow> rows,
    bool showDividers = false,
    EdgeInsets? padding,
  }) {
    return AppStatRowGroup(
      rows: rows,
      showDividers: showDividers,
      padding: padding ?? AppCardTheme.defaultPadding,
      spacing: 8,
    );
  }

  /// Factory for creating a compact stat group
  factory AppStatRowGroup.compact({
    required List<AppStatRow> rows,
    bool showDividers = false,
    EdgeInsets? padding,
  }) {
    return AppStatRowGroup(
      rows: rows,
      showDividers: showDividers,
      padding: padding ?? AppCardTheme.compactPadding,
      spacing: 4,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = AppCardThemeData.of(context);

    List<Widget> children = [];
    
    for (int i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      
      if (i < rows.length - 1) {
        if (spacing > 0) {
          children.add(SizedBox(height: spacing));
        }
        
        if (showDividers) {
          children.add(Divider(
            color: dividerColor ?? cardTheme.dividerColor.withValues(alpha: 0.3),
            height: spacing > 0 ? spacing : 1,
          ));
        }
      }
    }

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );

    if (padding != null) {
      content = Padding(
        padding: padding!,
        child: content,
      );
    }

    return content;
  }
}

/// A specialized stat row for displaying status information with colored indicators
class AppStatusRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isPositive;
  final IconData? icon;
  final IconData? statusIcon;
  final EdgeInsets? padding;

  const AppStatusRow({
    super.key,
    required this.label,
    required this.value,
    required this.isPositive,
    this.icon,
    this.statusIcon,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isPositive ? Colors.green : Colors.red;
    final defaultStatusIcon = isPositive ? Icons.check_circle : Icons.error;

    return AppStatRow(
      label: label,
      value: value,
      icon: icon,
      valueColor: statusColor,
      padding: padding,
      trailing: Icon(
        statusIcon ?? defaultStatusIcon,
        size: AppCardTheme.smallIconSize,
        color: statusColor,
      ),
    );
  }
}

/// A stat row with a progress indicator
class AppProgressRow extends StatelessWidget {
  final String label;
  final double progress; // 0.0 to 1.0
  final String? valueText;
  final Color? progressColor;
  final Color? backgroundColor;
  final EdgeInsets? padding;

  const AppProgressRow({
    super.key,
    required this.label,
    required this.progress,
    this.valueText,
    this.progressColor,
    this.backgroundColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardTheme = AppCardThemeData.of(context);

    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cardTheme.onSurfaceVariant,
                ),
              ),
              if (valueText != null)
                Text(
                  valueText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cardTheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: backgroundColor ?? cardTheme.outline.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              progressColor ?? cardTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}