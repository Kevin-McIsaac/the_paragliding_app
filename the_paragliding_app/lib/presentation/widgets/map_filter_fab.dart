import 'package:flutter/material.dart';

/// Inline filter button for map controls
/// Matches map control styling with indicator when filters are active
class MapFilterButton extends StatelessWidget {
  final bool hasActiveFilters;
  final bool sitesEnabled;
  final VoidCallback onPressed;

  const MapFilterButton({
    super.key,
    required this.hasActiveFilters,
    required this.sitesEnabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Show indicator if filters are active or sites are disabled
    final showIndicator = hasActiveFilters || !sitesEnabled;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          color: Color(0x80000000),
          borderRadius: BorderRadius.all(Radius.circular(4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Stack(
            children: [
              const Icon(
                Icons.tune,
                size: 20,
                color: Colors.white,
              ),
              if (showIndicator)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}