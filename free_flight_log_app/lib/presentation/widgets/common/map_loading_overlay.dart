import 'package:flutter/material.dart';

/// State of a loading item
enum LoadingItemState {
  loading,
  completed,
  error,
}

/// Data class for a single loading item in the overlay
class MapLoadingItem {
  final String label;
  final IconData icon;
  final Color iconColor;
  final int? count;
  final LoadingItemState state;

  const MapLoadingItem({
    required this.label,
    this.icon = Icons.place,
    this.iconColor = Colors.green,
    this.count,
    this.state = LoadingItemState.loading,
  });
}

/// Reusable loading overlay widget for map views
///
/// Provides a consistent loading indicator that appears at the top-right
/// of map views. Supports both single and multiple loading operations.
class MapLoadingOverlay extends StatelessWidget {
  final List<MapLoadingItem> items;

  /// Create a loading overlay with multiple items
  const MapLoadingOverlay.multiple({
    super.key,
    required this.items,
  });

  /// Create a loading overlay with a single item
  MapLoadingOverlay.single({
    super.key,
    required String label,
    IconData icon = Icons.place,
    Color iconColor = Colors.green,
    int? count,
  }) : items = [
          MapLoadingItem(
            label: label,
            icon: icon,
            iconColor: iconColor,
            count: count,
          )
        ];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 60,
      right: 16,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _buildLoadingItem(items[i]),
                if (i < items.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingItem(MapLoadingItem item) {
    return Row(
      children: [
        // Icon indicator
        Icon(
          item.icon,
          size: 16,
          color: item.iconColor.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 10),
        // State indicator (spinner, checkmark, or error)
        _buildStateIndicator(item.state),
        const SizedBox(width: 10),
        // Text label with optional count
        Flexible(
          child: Text(
            item.count != null ? '${item.label} (${item.count})' : item.label,
            style: TextStyle(
              color: item.state == LoadingItemState.error
                  ? Colors.red.shade300
                  : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStateIndicator(LoadingItemState state) {
    switch (state) {
      case LoadingItemState.loading:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
            strokeCap: StrokeCap.round,
          ),
        );
      case LoadingItemState.completed:
        return Icon(
          Icons.check_circle,
          size: 14,
          color: Colors.green.shade400,
        );
      case LoadingItemState.error:
        return Icon(
          Icons.error,
          size: 14,
          color: Colors.red.shade400,
        );
    }
  }
}