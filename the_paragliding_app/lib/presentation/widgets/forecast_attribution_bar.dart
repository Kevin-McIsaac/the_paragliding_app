import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/wind_forecast.dart';
import '../../services/weather_service.dart';

/// Shared widget for displaying weather forecast attribution with freshness indicator
///
/// Shows:
/// - Clickable attribution text (e.g., "Forecast: Open-Meteo")
/// - Age of forecast data (e.g., "Updated 2 hours ago")
/// - Staleness warning icon if forecast is >2 hours old
/// - Optional refresh button
///
/// Used by:
/// - Multi-site flyability screen - shows oldest forecast across all sites
/// - Site details dialog - shows individual site forecast freshness
/// - Week summary table - shows individual site forecast when expanded
class ForecastAttributionBar extends StatelessWidget {
  /// Optional forecast for showing age and freshness
  /// If null, only attribution text is shown
  final WindForecast? forecast;

  /// Optional callback for refresh button
  /// If null, refresh button is not shown
  final VoidCallback? onRefresh;

  /// Optional custom age text (for multi-site screens showing oldest forecast)
  /// If provided, overrides the age calculated from forecast.fetchedAt
  final String? customAgeText;

  /// Optional custom staleness indicator (for multi-site screens)
  /// If provided, overrides the staleness calculated from forecast.isFresh
  final bool? isCustomStale;

  const ForecastAttributionBar({
    super.key,
    this.forecast,
    this.onRefresh,
    this.customAgeText,
    this.isCustomStale,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _getAttributionText(),
      builder: (context, snapshot) {
        final attributionText = snapshot.data ?? 'Forecast: Open-Meteo';
        final ageText = customAgeText ?? _formatForecastAge();
        final isStale = isCustomStale ?? (forecast != null && !forecast!.isFresh);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Attribution text (clickable)
              TextButton(
                onPressed: () async {
                  await launchUrl(
                    Uri.parse('https://open-meteo.com'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  attributionText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Single space
              const SizedBox(width: 4),
              // Freshness indicator icon
              if (isStale) ...[
                const Icon(
                  Icons.warning_amber,
                  size: 14,
                  color: Colors.orange,
                ),
                const SizedBox(width: 4),
              ],
              // Combined refresh button with age text (idiomatic TextButton.icon pattern)
              if (onRefresh != null && ageText.isNotEmpty)
                TextButton.icon(
                  onPressed: onRefresh,
                  icon: Icon(
                    Icons.refresh,
                    size: 16,
                    color: isStale ? Colors.orange : Colors.white60,
                  ),
                  label: Text(
                    'Updated $ageText',
                    style: TextStyle(
                      fontSize: 11,
                      color: isStale
                          ? Colors.orange.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
              // Fallback: just refresh icon if no age text
              else if (onRefresh != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onRefresh,
                  tooltip: 'Refresh forecast',
                  color: isStale ? Colors.orange : Colors.white60,
                )
              // Fallback: just age text if no refresh callback
              else if (ageText.isNotEmpty)
                Text(
                  'Updated $ageText',
                  style: TextStyle(
                    fontSize: 11,
                    color: isStale
                        ? Colors.orange.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.5),
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Get attribution text with current weather model
  Future<String> _getAttributionText() async {
    final model = await WeatherService.instance.getCurrentModel();
    return model.attributionText;
  }

  /// Format the age of the forecast data (e.g., "2 minutes ago", "3 hours ago")
  String _formatForecastAge() {
    if (forecast == null) return '';

    final age = DateTime.now().difference(forecast!.fetchedAt);

    if (age.inMinutes < 1) {
      return 'just now';
    } else if (age.inMinutes < 60) {
      final minutes = age.inMinutes;
      return '$minutes minute${minutes == 1 ? '' : 's'} ago';
    } else {
      final hours = age.inHours;
      final minutes = age.inMinutes % 60;
      if (minutes == 0) {
        return '$hours hour${hours == 1 ? '' : 's'} ago';
      } else {
        return '$hours hour${hours == 1 ? '' : 's'}, $minutes min ago';
      }
    }
  }
}
