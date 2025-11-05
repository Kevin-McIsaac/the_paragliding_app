import 'package:flutter/material.dart';

/// Reusable widget that wraps a Table with a fixed left column
///
/// This creates a horizontally scrollable table where the first column
/// remains visible (sticky) while the rest of the table scrolls.
///
/// Implementation:
/// - Uses Stack with overlay pattern
/// - Full table scrolls horizontally
/// - First column overlays on top as a separate Table
/// - Using Table for overlay ensures perfect row height alignment
///
/// Usage:
/// ```dart
/// FixedColumnTable(
///   firstColumnWidth: 120,
///   fullTable: Table(children: [fullRows...]),
///   firstColumnTable: Table(children: [firstColumnOnlyRows...]),
/// )
/// ```
class FixedColumnTable extends StatelessWidget {
  /// Width of the fixed first column
  final double firstColumnWidth;

  /// The full table (including first column) that will scroll horizontally
  final Table fullTable;

  /// A table containing only the first column
  /// Should have same number of rows as fullTable
  /// Each TableRow should have only 1 cell (the first column cell)
  final Table firstColumnTable;

  const FixedColumnTable({
    super.key,
    required this.firstColumnWidth,
    required this.fullTable,
    required this.firstColumnTable,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Full scrollable table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: fullTable,
        ),

        // Fixed left column overlay (as a Table for perfect height matching)
        Container(
          width: firstColumnWidth,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              right: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1.0,
              ),
            ),
          ),
          child: firstColumnTable,
        ),
      ],
    );
  }
}
