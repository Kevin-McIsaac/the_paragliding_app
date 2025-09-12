import 'package:flutter/material.dart';
import '../../../utils/card_expansion_manager.dart';

/// A reusable expansion card widget that wraps ExpansionTile with consistent styling.
/// 
/// Used across DataManagementScreen, FlightDetailScreen, and PreferencesScreen
/// to provide consistent card styling, expansion state management, and theming.
class AppExpansionCard extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final EdgeInsets? padding;
  final double? elevation;
  final Color? backgroundColor;
  final String? expansionKey;
  final CardExpansionManager? expansionManager;

  const AppExpansionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.children,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.padding,
    this.elevation,
    this.backgroundColor,
    this.expansionKey,
    this.expansionManager,
  });

  /// Factory for creating a data management expansion card with icon and subtitle
  factory AppExpansionCard.dataManagement({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
    required String expansionKey,
    required CardExpansionManager expansionManager,
    ValueChanged<bool>? onExpansionChanged,
  }) {
    return AppExpansionCard(
      title: Text(title),
      subtitle: Text(subtitle),
      leading: Icon(icon),
      expansionKey: expansionKey,
      expansionManager: expansionManager,
      onExpansionChanged: onExpansionChanged,
      children: children,
    );
  }

  /// Factory for creating a flight detail expansion card with custom content
  factory AppExpansionCard.flightDetail({
    required Widget title,
    Widget? subtitle,
    IconData? icon,
    required List<Widget> children,
    bool initiallyExpanded = false,
    ValueChanged<bool>? onExpansionChanged,
  }) {
    return AppExpansionCard(
      title: title,
      subtitle: subtitle,
      leading: icon != null ? Icon(icon) : null,
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: onExpansionChanged,
      children: children,
    );
  }

  /// Factory for creating a preferences expansion card with section styling
  factory AppExpansionCard.preferences({
    required String title,
    String? subtitle,
    IconData? icon,
    required List<Widget> children,
    String? expansionKey,
    CardExpansionManager? expansionManager,
    ValueChanged<bool>? onExpansionChanged,
  }) {
    return AppExpansionCard(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      leading: icon != null ? Icon(icon) : null,
      expansionKey: expansionKey,
      expansionManager: expansionManager,
      onExpansionChanged: onExpansionChanged,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    
    // Determine initial expansion state
    bool currentlyExpanded = initiallyExpanded;
    if (expansionKey != null && expansionManager != null) {
      currentlyExpanded = expansionManager!.getState(expansionKey!);
    }

    return Card(
      elevation: elevation ?? 2.0,
      color: backgroundColor,
      child: ExpansionTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        initiallyExpanded: currentlyExpanded,
        onExpansionChanged: (expanded) {
          // Update expansion manager if provided
          if (expansionKey != null && expansionManager != null) {
            expansionManager!.setState(expansionKey!, expanded);
          }
          
          // Call user-provided callback
          onExpansionChanged?.call(expanded);
        },
        children: [
          if (children.isNotEmpty)
            Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
        ],
      ),
    );
  }
}

/// A specialized expansion card for sections with a header and content
class AppSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget content;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final String? expansionKey;
  final CardExpansionManager? expansionManager;
  final EdgeInsets? contentPadding;

  const AppSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.content,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.expansionKey,
    this.expansionManager,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return AppExpansionCard(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      leading: icon != null ? Icon(icon) : null,
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: onExpansionChanged,
      expansionKey: expansionKey,
      expansionManager: expansionManager,
      padding: contentPadding ?? const EdgeInsets.all(16),
      children: [content],
    );
  }
}

/// A group of expansion cards with consistent spacing
class AppExpansionCardGroup extends StatelessWidget {
  final List<AppExpansionCard> cards;
  final double spacing;
  final EdgeInsets? padding;

  const AppExpansionCardGroup({
    super.key,
    required this.cards,
    this.spacing = 24.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(top: 16, bottom: 16),
      child: Column(
        children: cards
            .expand((card) => [
                  card,
                  if (card != cards.last) SizedBox(height: spacing)
                ])
            .toList(),
      ),
    );
  }
}