import 'package:flutter/material.dart';

/// A compact search field sized to sit as an [AppBar] title.
///
/// Follows the same pattern as other common widgets (AppStatCard, AppEmptyState)
/// and keeps the two search screens visually identical.
///
/// Colours are derived from the theme rather than hardcoded. The AppBar is light
/// under the light theme (Material 3 default `surface`) and dark under the dark
/// theme, so a fixed white would be invisible on one of them.
///
/// Usage:
/// ```dart
/// AppBar(
///   title: AppSearchField(
///     controller: _searchController,
///     hintText: 'Search nearby sites...',
///     onChanged: _onSearchChanged,
///   ),
/// )
/// ```
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The dark theme sets appBarTheme.foregroundColor explicitly; the light theme
    // leaves it null and falls through to the Material 3 default of onSurface.
    final foreground =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;

    const textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        style: textStyle.copyWith(color: foreground),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: textStyle.copyWith(
            color: foreground.withValues(alpha: 0.7),
          ),
          prefixIcon: Icon(Icons.search, size: 16, color: foreground),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, child) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(Icons.clear, size: 16, color: foreground),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                padding: EdgeInsets.zero,
              );
            },
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}
