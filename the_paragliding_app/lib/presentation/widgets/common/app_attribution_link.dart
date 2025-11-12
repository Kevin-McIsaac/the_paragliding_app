import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/logging_service.dart';

/// A reusable widget for displaying clickable attribution links with icons.
///
/// Follows the same pattern as other common widgets (AppStatCard, AppExpansionCard)
/// and provides consistent styling for all attribution links in the About screen.
///
/// Usage:
/// ```dart
/// // Standard link (email, single attribution)
/// AppAttributionLink.standard(
///   url: 'mailto:email@example.com',
///   icon: Icons.email,
///   text: 'email@example.com',
/// )
///
/// // Compact link (for lists like weather providers)
/// AppAttributionLink.compact(
///   url: 'https://example.com',
///   icon: Icons.cloud,
///   text: 'Weather Provider',
/// )
/// ```
class AppAttributionLink extends StatelessWidget {
  final String url;
  final IconData icon;
  final String text;
  final double iconSize;
  final EdgeInsets padding;
  final bool useExpanded;

  const AppAttributionLink({
    super.key,
    required this.url,
    required this.icon,
    required this.text,
    this.iconSize = 20,
    this.padding = EdgeInsets.zero,
    this.useExpanded = false,
  });

  /// Standard attribution link with larger icon (20px) for primary links.
  /// Used for: email contact, OSM links, ParaglidingEarth, Open-Meteo.
  factory AppAttributionLink.standard({
    required String url,
    required IconData icon,
    required String text,
  }) {
    return AppAttributionLink(
      url: url,
      icon: icon,
      text: text,
      iconSize: 20,
      padding: EdgeInsets.zero,
      useExpanded: false,
    );
  }

  /// Compact attribution link with smaller icon (18px) and bottom padding.
  /// Used for: weather provider lists with consistent spacing.
  factory AppAttributionLink.compact({
    required String url,
    required IconData icon,
    required String text,
  }) {
    return AppAttributionLink(
      url: url,
      icon: icon,
      text: text,
      iconSize: 18,
      padding: const EdgeInsets.only(bottom: 8),
      useExpanded: true,
    );
  }

  Future<void> _launchUrl(BuildContext context) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      LoggingService.error('AppAttributionLink: Could not launch URL: $url', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _launchUrl(context),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Icon(
              icon,
              size: iconSize,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            if (useExpanded)
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              )
            else
              Text(
                text,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
